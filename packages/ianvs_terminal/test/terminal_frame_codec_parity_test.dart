import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal/src/runtime/terminal_frame_decoder.dart';
import 'package:ianvs_terminal/src/transport/terminal_frame_validation_limits.dart';

import 'support/terminal_frame_wire_fixture.dart';

void main() {
  group('terminal frame JSON/protobuf parity', () {
    test('complete payloads have equal recursive projections and hashes', () {
      final fixture = completeTerminalFrameWireFixture();
      final jsonFrame = TerminalFrameDiff.fromJson(fixture.json);
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        fixture.protobufBytes,
      );

      expect(
        terminalFrameProjection(jsonFrame),
        terminalFrameProjection(protobufFrame),
      );
      expect(
        terminalBenchmarkViewportHash(jsonFrame),
        terminalBenchmarkViewportHash(protobufFrame),
      );
    });

    test('global bottom row preserves missing-field and zero semantics', () {
      final legacyJson = TerminalFrameDiff.fromJson(_jsonFrame());
      final zeroJson = TerminalFrameDiff.fromJson(<String, Object?>{
        ..._jsonFrame(),
        'global_bottom_row': 0,
      });
      final malformedJson = TerminalFrameDiff.fromJson(<String, Object?>{
        ..._jsonFrame(),
        'global_bottom_row': -1,
      });
      final legacyProtobuf = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 1,
        ).writeToBuffer(),
      );
      final zeroProtobuf = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 1,
          globalBottomRow: Int64.ZERO,
        ).writeToBuffer(),
      );

      expect(legacyJson.globalBottomRow, isNull);
      expect(legacyProtobuf.globalBottomRow, isNull);
      expect(malformedJson.globalBottomRow, isNull);
      expect(zeroJson.globalBottomRow, 0);
      expect(zeroProtobuf.globalBottomRow, 0);
    });

    test('OSC 50 font family preserves optional bounded wire semantics', () {
      final jsonFrame = TerminalFrameDiff.fromJson(<String, Object?>{
        ..._jsonFrame(),
        'font_family': '  Courier Prime  ',
      });
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 1,
          fontFamily: '  Courier Prime  ',
        ).writeToBuffer(),
      );
      final legacyJson = TerminalFrameDiff.fromJson(_jsonFrame());
      final legacyProtobuf = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 1,
        ).writeToBuffer(),
      );
      final oversized = List<String>.filled(257, 'x').join();
      final invalidJson = TerminalFrameDiff.fromJson(<String, Object?>{
        ..._jsonFrame(),
        'font_family': oversized,
      });
      final invalidProtobuf = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 1,
          fontFamily: 'Bad\u0085Font',
        ).writeToBuffer(),
      );

      expect(jsonFrame.fontFamily, 'Courier Prime');
      expect(protobufFrame.fontFamily, 'Courier Prime');
      expect(legacyJson.fontFamily, isNull);
      expect(legacyProtobuf.fontFamily, isNull);
      expect(invalidJson.fontFamily, isNull);
      expect(invalidProtobuf.fontFamily, isNull);
    });

    test(
      'dynamic cursor overrides preserve optional compatibility semantics',
      () {
        final legacyJson = TerminalFrameDiff.fromJson(_jsonFrame());
        final dynamicJson = TerminalFrameDiff.fromJson(<String, Object?>{
          ..._jsonFrame(),
          'cursor': <String, Object?>{
            'row': 0,
            'col': 0,
            'visible': true,
            'shape': 'beam',
            'blink': false,
          },
        });
        final legacyProtobuf = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            viewportRows: 1,
            viewportCols: 1,
            cursor: frame_pb.TerminalCursor(visible: true),
          ).writeToBuffer(),
        );
        final dynamicProtobuf = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            viewportRows: 1,
            viewportCols: 1,
            cursor: frame_pb.TerminalCursor(
              visible: true,
              shape: 'beam',
              blink: false,
            ),
          ).writeToBuffer(),
        );

        expect(legacyJson.cursor.shape, isNull);
        expect(legacyJson.cursor.blink, isNull);
        expect(legacyProtobuf.cursor.shape, isNull);
        expect(legacyProtobuf.cursor.blink, isNull);
        expect(dynamicJson.cursor.shape, TerminalCursorShape.beam);
        expect(dynamicJson.cursor.blink, isFalse);
        expect(dynamicProtobuf.cursor.shape, TerminalCursorShape.beam);
        expect(dynamicProtobuf.cursor.blink, isFalse);
      },
    );

    test('cursor guide state and color preserve JSON/protobuf parity', () {
      final jsonFrame = TerminalFrameDiff.fromJson(<String, Object?>{
        ..._jsonFrame(),
        'cursor': <String, Object?>{
          'row': 0,
          'col': 0,
          'visible': true,
          'highlight_line': true,
        },
        'cursor_guide_color': '#2A80D7',
      });
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 1,
          cursor: frame_pb.TerminalCursor(visible: true, highlightLine: true),
          cursorGuideColor: frame_pb.ColorRgb(present: true, rgb: 0x2A80D7),
        ).writeToBuffer(),
      );

      expect(jsonFrame.cursor.highlightLine, isTrue);
      expect(protobufFrame.cursor.highlightLine, isTrue);
      expect(jsonFrame.cursorGuideColor, const Color(0xFF2A80D7));
      expect(protobufFrame.cursorGuideColor, const Color(0xFF2A80D7));

      final legacyJson = TerminalFrameDiff.fromJson(_jsonFrame());
      final legacyProtobuf = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 1,
        ).writeToBuffer(),
      );
      expect(legacyJson.cursor.highlightLine, isFalse);
      expect(legacyProtobuf.cursor.highlightLine, isFalse);
      expect(legacyJson.cursorGuideColor, isNull);
      expect(legacyProtobuf.cursorGuideColor, isNull);
    });

    test('OSC 8 protocol identifiers survive JSON and protobuf decoding', () {
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(
          hyperlinks: <Object?>[
            <String, Object?>{
              'row': 0,
              'start_col': 0,
              'end_col': 4,
              'uri': 'https://example.test',
              'protocol_id': 'first',
            },
          ],
        ),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 80,
          hyperlinks: <frame_pb.TerminalHyperlinkRange>[
            frame_pb.TerminalHyperlinkRange(
              row: 0,
              startCol: 0,
              endCol: 4,
              uri: 'https://example.test',
              protocolId: 'first',
            ),
          ],
        ).writeToBuffer(),
      );

      expect(jsonFrame.hyperlinks.single.protocolId, 'first');
      expect(protobufFrame.hyperlinks.single.protocolId, 'first');
    });

    test('graphics identities preserve values above uint32 range', () {
      const placementId = 4294967301;
      const renderId = 4294967303;
      const assetId = 4294967307;
      const assetVersion = 3205628038470320;
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(
          graphics: <Object?>[
            <String, Object?>{
              ..._jsonGraphic(),
              'placement_id': placementId,
              'render_id': renderId,
              'asset_id': assetId,
              'asset_version': assetVersion,
            },
          ],
        ),
      );
      final protobufAssetKey = frame_pb.TerminalGraphicAssetKey()
        ..setField(1, Int64(assetId))
        ..setField(2, Int64(assetVersion));
      final protobufGraphic = _protobufGraphic()
        ..setField(1, Int64(placementId))
        ..setField(2, Int64(renderId))
        ..assetKey = protobufAssetKey;
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 80,
          graphics: <frame_pb.TerminalGraphicPlacement>[protobufGraphic],
        ).writeToBuffer(),
      );

      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
      expect(protobufFrame.graphics.single.assetKey.version, assetVersion);
    });

    test('dimensions above uint16 range clamp equally', () {
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(viewportRows: 70000, viewportCols: 90000),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 70000,
          viewportCols: 90000,
        ).writeToBuffer(),
      );

      expect(jsonFrame.viewportRows, 0xffff);
      expect(jsonFrame.viewportCols, 0xffff);
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test(
      'duplicate and out-of-range rows normalize and clip complete columns equally',
      () {
        final jsonRows = <Object?>[
          <String, Object?>{'index': 7, 'text': 'outside'},
          <String, Object?>{'index': 2, 'text': 'ok'},
          <String, Object?>{'index': 1, 'text': 'old'},
          <String, Object?>{'index': 1, 'text': 'A界Z'},
        ];
        final protobufRows = <frame_pb.TerminalRow>[
          frame_pb.TerminalRow(index: 7, text: 'outside'),
          frame_pb.TerminalRow(index: 2, text: 'ok'),
          frame_pb.TerminalRow(index: 1, text: 'old'),
          frame_pb.TerminalRow(index: 1, text: 'A界Z'),
        ];

        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(rows: jsonRows, viewportRows: 3, viewportCols: 3),
        );
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            rows: protobufRows,
            viewportRows: 3,
            viewportCols: 3,
          ).writeToBuffer(),
        );

        expect(
          jsonFrame.rows
              .map((row) => (row.index, row.text))
              .toList(growable: false),
          <(int, String)>[(1, 'A界'), (2, 'ok')],
        );
        expect(
          terminalFrameProjection(protobufFrame),
          terminalFrameProjection(jsonFrame),
        );
      },
    );

    test('duplicate rows do not consume the unique row cap', () {
      const viewportRows = 1;
      final validCap = _maxViewportBoundedEntries(viewportRows);
      expect(validCap, 65);
      final jsonRows = <Object?>[
        for (var index = 0; index < validCap; index += 1)
          <String, Object?>{'index': 0, 'text': 'old-$index'},
        <String, Object?>{'index': 0, 'text': 'new'},
      ];
      final protobufRows = <frame_pb.TerminalRow>[
        for (var index = 0; index < validCap; index += 1)
          frame_pb.TerminalRow(index: 0, text: 'old-$index'),
        frame_pb.TerminalRow(index: 0, text: 'new'),
      ];
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(rows: jsonRows, viewportRows: viewportRows),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          rows: protobufRows,
          viewportRows: viewportRows,
          viewportCols: 80,
        ).writeToBuffer(),
      );

      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
      expect(jsonFrame.rows, hasLength(1));
      expect(jsonFrame.rows.single.text, 'new');
      expect(protobufFrame.rows, hasLength(1));
      expect(protobufFrame.rows.single.text, 'new');
    });

    test('style runs cap at 1024 for both formats', () {
      final jsonRuns = List<Object?>.generate(
        1025,
        (index) => <String, Object?>{'start': index, 'end': index + 1},
      );
      final protobufRuns = List<frame_pb.TerminalStyleRun>.generate(
        1025,
        (index) => frame_pb.TerminalStyleRun(start: index, end: index + 1),
      );
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(
          rows: <Object?>[
            <String, Object?>{'index': 0, 'text': 'x', 'style_runs': jsonRuns},
          ],
        ),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          rows: <frame_pb.TerminalRow>[
            frame_pb.TerminalRow(index: 0, text: 'x', styleRuns: protobufRuns),
          ],
          viewportRows: 1,
          viewportCols: 80,
        ).writeToBuffer(),
      );

      expect(jsonFrame.rows.single.styleRuns, hasLength(1024));
      expect(protobufFrame.rows.single.styleRuns, hasLength(1024));
      final jsonIdentity = jsonFrame.rows.single.styleRuns
          .map((run) => (run.start, run.end))
          .toList(growable: false);
      final protobufIdentity = protobufFrame.rows.single.styleRuns
          .map((run) => (run.start, run.end))
          .toList(growable: false);
      expect(protobufIdentity, jsonIdentity);
      expect(jsonIdentity.first, (0, 1));
      expect(jsonIdentity.last, (1023, 1024));
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test('hyperlinks cap at 4096 for both formats', () {
      final jsonLinks = List<Object?>.generate(
        4097,
        (index) => <String, Object?>{
          'row': 0,
          'start_col': index,
          'end_col': index + 1,
          'uri': 'https://example.test/$index',
        },
      );
      final protobufLinks = List<frame_pb.TerminalHyperlinkRange>.generate(
        4097,
        (index) => frame_pb.TerminalHyperlinkRange(
          row: 0,
          startCol: index,
          endCol: index + 1,
          uri: 'https://example.test/$index',
        ),
      );

      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(hyperlinks: jsonLinks),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 80,
          hyperlinks: protobufLinks,
        ).writeToBuffer(),
      );

      expect(jsonFrame.hyperlinks, hasLength(4096));
      expect(protobufFrame.hyperlinks, hasLength(4096));
      final jsonIdentity = jsonFrame.hyperlinks
          .map((link) => (link.startCol, link.endCol, link.uri))
          .toList(growable: false);
      final protobufIdentity = protobufFrame.hyperlinks
          .map((link) => (link.startCol, link.endCol, link.uri))
          .toList(growable: false);
      expect(protobufIdentity, jsonIdentity);
      expect(jsonIdentity.first, (0, 1, 'https://example.test/0'));
      expect(jsonIdentity.last, (4095, 4096, 'https://example.test/4095'));
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test('inline images cap at 32 for both formats', () {
      final jsonImages = List<Object?>.generate(
        33,
        (index) => <String, Object?>{
          'data': base64Encode(<int>[index]),
          'row': 0,
          'col': 0,
          'width_cells': 1,
          'height_cells': 1,
        },
      );
      final protobufImages = List<frame_pb.TerminalInlineImage>.generate(
        33,
        (index) => frame_pb.TerminalInlineImage(
          data: base64Encode(<int>[index]),
          row: 0,
          col: 0,
          widthCells: 1,
          heightCells: 1,
        ),
      );

      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(inlineImages: jsonImages),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 80,
          inlineImages: protobufImages,
        ).writeToBuffer(),
      );

      expect(jsonFrame.inlineImages, hasLength(32));
      expect(protobufFrame.inlineImages, hasLength(32));
      final jsonIdentity = jsonFrame.inlineImages
          .map((image) => image.bytes.toList(growable: false))
          .toList(growable: false);
      final protobufIdentity = protobufFrame.inlineImages
          .map((image) => image.bytes.toList(growable: false))
          .toList(growable: false);
      expect(protobufIdentity, jsonIdentity);
      expect(jsonIdentity.first, <int>[0]);
      expect(jsonIdentity.last, <int>[31]);
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test('dirty ranges clamp, sort, and merge equally', () {
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(
          viewportRows: 5,
          dirtyRanges: <Object?>[
            <String, Object?>{'start': -4, 'end': 2},
            <String, Object?>{'start': 4, 'end': 99},
            <String, Object?>{'start': 1, 'end': 4},
            <String, Object?>{'start': 5, 'end': 5},
          ],
        ),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 5,
          viewportCols: 80,
          dirtyRanges: <frame_pb.TerminalDirtyRange>[
            frame_pb.TerminalDirtyRange(start: 0, end: 2),
            frame_pb.TerminalDirtyRange(start: 4, end: 99),
            frame_pb.TerminalDirtyRange(start: 1, end: 4),
            frame_pb.TerminalDirtyRange(start: 5, end: 5),
          ],
        ).writeToBuffer(),
      );

      expect(
        jsonFrame.dirtyRanges.map((range) => (range.start, range.end)),
        <(int, int)>[(0, 5)],
      );
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test(
      'missing schema and unknown wire values use compatibility defaults',
      () {
        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(
            frameKind: 'future-kind',
            modes: <String, Object?>{
              'mouse_mode': 'future-mode',
              'mouse_encoding': 'future-encoding',
            },
          )..remove('frame_schema_version'),
        );
        final protobuf = frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 80,
          modes: frame_pb.TerminalFrameModes(
            mouseMode: 'future-mode',
            mouseEncoding: 'future-encoding',
          ),
        ).writeToBuffer();
        final protobufWithUnknownKind = Uint8List.fromList(<int>[
          ...protobuf,
          0x10,
          0x63,
        ]);
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          protobufWithUnknownKind,
        );

        expect(jsonFrame.frameSchemaVersion, 'terminal-frame-diff-v1');
        expect(jsonFrame.frameKind, TerminalFrameKind.snapshot);
        expect(jsonFrame.modes.mouseMode, 'off');
        expect(jsonFrame.modes.mouseEncoding, 'default');
        expect(
          terminalFrameProjection(protobufFrame),
          terminalFrameProjection(jsonFrame),
        );
      },
    );

    for (final preserveAspectRatio in <bool>[true, false]) {
      test(
        'explicit preserveAspectRatio=$preserveAspectRatio decodes equally',
        () {
          final fixture = completeTerminalFrameWireFixture(
            preserveAspectRatio: preserveAspectRatio,
          );
          final jsonFrame = TerminalFrameDiff.fromJson(fixture.json);
          final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
            fixture.protobufBytes,
          );

          expect(
            jsonFrame.graphics.single.preserveAspectRatio,
            preserveAspectRatio,
          );
          expect(
            terminalFrameProjection(protobufFrame),
            terminalFrameProjection(jsonFrame),
          );
        },
      );
    }

    test(
      'omitted legacy aspect-ratio defaults intentionally differ by wire',
      () {
        final jsonGraphic = _jsonGraphic()..remove('preserve_aspect_ratio');
        final protobufGraphic = _protobufGraphic()..clearPreserveAspectRatio();

        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(graphics: <Object?>[jsonGraphic]),
        );
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            viewportRows: 1,
            viewportCols: 80,
            graphics: <frame_pb.TerminalGraphicPlacement>[protobufGraphic],
          ).writeToBuffer(),
        );

        expect(jsonFrame.graphics.single.preserveAspectRatio, isTrue);
        expect(protobufFrame.graphics.single.preserveAspectRatio, isFalse);
      },
    );

    test('unknown protobuf field 99 is ignored', () {
      final fixture = completeTerminalFrameWireFixture();
      final bytesWithUnknownField = Uint8List.fromList(<int>[
        ...fixture.protobufBytes,
        0x98,
        0x06,
        0x01,
      ]);

      expect(
        terminalFrameProjection(
          TerminalFrameDiff.fromProtobufBytes(bytesWithUnknownField),
        ),
        terminalFrameProjection(
          TerminalFrameDiff.fromProtobufBytes(fixture.protobufBytes),
        ),
      );
    });

    test('explicit non-current schema text is trimmed and preserved', () {
      final fixture = completeTerminalFrameWireFixture();
      final json = Map<String, Object?>.of(fixture.json)
        ..['frame_schema_version'] = ' terminal-frame-diff-v9 ';
      final protobuf = fixture.protobuf.deepCopy()
        ..frameSchemaVersion = ' terminal-frame-diff-v9 ';

      final jsonFrame = TerminalFrameDiff.fromJson(json);
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        protobuf.writeToBuffer(),
      );

      expect(jsonFrame.frameSchemaVersion, 'terminal-frame-diff-v9');
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test('public factories and decoder facade have equal projections', () {
      final fixture = completeTerminalFrameWireFixture();
      const decoder = TerminalFrameDecoder();

      expect(
        terminalFrameProjection(TerminalFrameDiff.fromJson(fixture.json)),
        terminalFrameProjection(decoder.decodeJson(fixture.jsonString)!.frame),
      );
      expect(
        terminalFrameProjection(
          TerminalFrameDiff.fromProtobufBytes(fixture.protobufBytes),
        ),
        terminalFrameProjection(
          decoder.decodeProtobuf(fixture.protobufBytes)!.frame,
        ),
      );
    });

    test(
      'empty protobuf public factory returns a normalized default frame',
      () {
        final frame = TerminalFrameDiff.fromProtobufBytes(const <int>[]);

        expect(frame.frameSchemaVersion, 'terminal-frame-diff-v1');
        expect(frame.frameKind, TerminalFrameKind.snapshot);
        expect(frame.viewportRows, 0);
        expect(frame.viewportCols, 0);
        expect(frame.rows, isEmpty);
        expect(frame.dirtyRanges, isEmpty);
      },
    );

    test('row scan accepts its last in-bound item and rejects the next', () {
      const viewportRows = 2;
      final scanLimit = _maxEntriesToScan(
        _maxViewportBoundedEntries(viewportRows),
      );
      final jsonRows = <Object?>[
        for (var index = 0; index < scanLimit - 1; index += 1)
          <String, Object?>{},
        <String, Object?>{'index': 0, 'text': 'inside'},
        <String, Object?>{'index': 1, 'text': 'outside'},
      ];
      final protobufRows = <frame_pb.TerminalRow>[
        for (var index = 0; index < scanLimit - 1; index += 1)
          frame_pb.TerminalRow(index: 99, text: 'invalid'),
        frame_pb.TerminalRow(index: 0, text: 'inside'),
        frame_pb.TerminalRow(index: 1, text: 'outside'),
      ];
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(rows: jsonRows, viewportRows: viewportRows),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          rows: protobufRows,
          viewportRows: viewportRows,
          viewportCols: 80,
        ).writeToBuffer(),
      );

      expect(
        jsonFrame.rows.map((row) => (row.index, row.text)),
        <(int, String)>[(0, 'inside')],
      );
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test(
      'style-run scan accepts its last in-bound item and rejects the next',
      () {
        final scanLimit = _maxEntriesToScan(_maxStyleRunsPerRow);
        final jsonRuns = <Object?>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            <String, Object?>{'start': 0, 'end': 0},
          <String, Object?>{'start': 1, 'end': 2},
          <String, Object?>{'start': 2, 'end': 3},
        ];
        final protobufRuns = <frame_pb.TerminalStyleRun>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            frame_pb.TerminalStyleRun(start: 0, end: 0),
          frame_pb.TerminalStyleRun(start: 1, end: 2),
          frame_pb.TerminalStyleRun(start: 2, end: 3),
        ];
        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(
            rows: <Object?>[
              <String, Object?>{
                'index': 0,
                'text': 'xxx',
                'style_runs': jsonRuns,
              },
            ],
          ),
        );
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            rows: <frame_pb.TerminalRow>[
              frame_pb.TerminalRow(
                index: 0,
                text: 'xxx',
                styleRuns: protobufRuns,
              ),
            ],
            viewportRows: 1,
            viewportCols: 80,
          ).writeToBuffer(),
        );

        expect(
          jsonFrame.rows.single.styleRuns.map((run) => (run.start, run.end)),
          <(int, int)>[(1, 2)],
        );
        expect(
          terminalFrameProjection(protobufFrame),
          terminalFrameProjection(jsonFrame),
        );
      },
    );

    test(
      'hyperlink scan accepts its last in-bound item and rejects the next',
      () {
        final scanLimit = _maxEntriesToScan(_maxHyperlinksPerFrame);
        final jsonLinks = <Object?>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            <String, Object?>{
              'row': 0,
              'start_col': 0,
              'end_col': 0,
              'uri': 'https://invalid.test',
            },
          <String, Object?>{
            'row': 0,
            'start_col': 0,
            'end_col': 1,
            'uri': 'https://inside.test',
          },
          <String, Object?>{
            'row': 0,
            'start_col': 1,
            'end_col': 2,
            'uri': 'https://outside.test',
          },
        ];
        final protobufLinks = <frame_pb.TerminalHyperlinkRange>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            frame_pb.TerminalHyperlinkRange(
              row: 0,
              startCol: 0,
              endCol: 0,
              uri: 'https://invalid.test',
            ),
          frame_pb.TerminalHyperlinkRange(
            row: 0,
            startCol: 0,
            endCol: 1,
            uri: 'https://inside.test',
          ),
          frame_pb.TerminalHyperlinkRange(
            row: 0,
            startCol: 1,
            endCol: 2,
            uri: 'https://outside.test',
          ),
        ];
        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(hyperlinks: jsonLinks),
        );
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            viewportRows: 1,
            viewportCols: 80,
            hyperlinks: protobufLinks,
          ).writeToBuffer(),
        );

        expect(jsonFrame.hyperlinks.map((link) => link.uri), <String>[
          'https://inside.test',
        ]);
        expect(
          terminalFrameProjection(protobufFrame),
          terminalFrameProjection(jsonFrame),
        );
      },
    );

    test(
      'inline-image scan accepts its last in-bound item and rejects the next',
      () {
        final scanLimit = _maxEntriesToScan(_maxInlineImagesPerFrame);
        final insideData = base64Encode(const <int>[1]);
        final outsideData = base64Encode(const <int>[2]);
        final jsonImages = <Object?>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            <String, Object?>{'data': ''},
          <String, Object?>{
            'data': insideData,
            'row': 0,
            'col': 0,
            'width_cells': 1,
            'height_cells': 1,
          },
          <String, Object?>{
            'data': outsideData,
            'row': 0,
            'col': 1,
            'width_cells': 1,
            'height_cells': 1,
          },
        ];
        final protobufImages = <frame_pb.TerminalInlineImage>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            frame_pb.TerminalInlineImage(data: ''),
          frame_pb.TerminalInlineImage(
            data: insideData,
            row: 0,
            col: 0,
            widthCells: 1,
            heightCells: 1,
          ),
          frame_pb.TerminalInlineImage(
            data: outsideData,
            row: 0,
            col: 1,
            widthCells: 1,
            heightCells: 1,
          ),
        ];
        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(inlineImages: jsonImages),
        );
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            viewportRows: 1,
            viewportCols: 80,
            inlineImages: protobufImages,
          ).writeToBuffer(),
        );

        expect(
          jsonFrame.inlineImages.map(
            (image) => image.bytes.toList(growable: false),
          ),
          <List<int>>[
            <int>[1],
          ],
        );
        expect(
          terminalFrameProjection(protobufFrame),
          terminalFrameProjection(jsonFrame),
        );
      },
    );

    test(
      'dirty-range scan accepts its last in-bound item and rejects the next',
      () {
        const viewportRows = 2;
        final scanLimit = _maxEntriesToScan(
          _maxViewportBoundedEntries(viewportRows),
        );
        final jsonRanges = <Object?>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            <String, Object?>{},
          <String, Object?>{'start': 0, 'end': 1},
          <String, Object?>{'start': 1, 'end': 2},
        ];
        final protobufRanges = <frame_pb.TerminalDirtyRange>[
          for (var index = 0; index < scanLimit - 1; index += 1)
            frame_pb.TerminalDirtyRange(start: 2, end: 2),
          frame_pb.TerminalDirtyRange(start: 0, end: 1),
          frame_pb.TerminalDirtyRange(start: 1, end: 2),
        ];
        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(viewportRows: viewportRows, dirtyRanges: jsonRanges),
        );
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            viewportRows: viewportRows,
            viewportCols: 80,
            dirtyRanges: protobufRanges,
          ).writeToBuffer(),
        );

        expect(
          jsonFrame.dirtyRanges.map((range) => (range.start, range.end)),
          <(int, int)>[(0, 1)],
        );
        expect(
          terminalFrameProjection(protobufFrame),
          terminalFrameProjection(jsonFrame),
        );
      },
    );

    test('context-invalid rows do not consume the valid row cap', () {
      const viewportRows = 1;
      final validCap = _maxViewportBoundedEntries(viewportRows);
      expect(validCap, 65);
      final jsonRows = <Object?>[
        for (var index = 0; index < validCap; index += 1)
          <String, Object?>{'index': 99, 'text': 'invalid-$index'},
        <String, Object?>{'index': 0, 'text': 'inside'},
      ];
      final protobufRows = <frame_pb.TerminalRow>[
        for (var index = 0; index < validCap; index += 1)
          frame_pb.TerminalRow(index: 99, text: 'invalid-$index'),
        frame_pb.TerminalRow(index: 0, text: 'inside'),
      ];
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(rows: jsonRows, viewportRows: viewportRows),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          rows: protobufRows,
          viewportRows: viewportRows,
          viewportCols: 80,
        ).writeToBuffer(),
      );
      const expected = <(int, String)>[(0, 'inside')];

      expect(protobufFrame.rows.map((row) => (row.index, row.text)), expected);
      expect(jsonFrame.rows.map((row) => (row.index, row.text)), expected);
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test('context-invalid dirty ranges do not consume the valid range cap', () {
      const viewportRows = 1;
      final validCap = _maxViewportBoundedEntries(viewportRows);
      expect(validCap, 65);
      final jsonRanges = <Object?>[
        for (var index = 0; index < validCap; index += 1)
          <String, Object?>{'start': 2, 'end': 2},
        <String, Object?>{'start': 0, 'end': 1},
      ];
      final protobufRanges = <frame_pb.TerminalDirtyRange>[
        for (var index = 0; index < validCap; index += 1)
          frame_pb.TerminalDirtyRange(start: 2, end: 2),
        frame_pb.TerminalDirtyRange(start: 0, end: 1),
      ];
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(viewportRows: viewportRows, dirtyRanges: jsonRanges),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: viewportRows,
          viewportCols: 80,
          dirtyRanges: protobufRanges,
        ).writeToBuffer(),
      );
      const expected = <(int, int)>[(0, 1)];

      expect(
        protobufFrame.dirtyRanges.map((range) => (range.start, range.end)),
        expected,
      );
      expect(
        jsonFrame.dirtyRanges.map((range) => (range.start, range.end)),
        expected,
      );
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test('context-invalid hyperlinks do not consume the valid link cap', () {
      final jsonLinks = <Object?>[
        for (var index = 0; index < _maxHyperlinksPerFrame; index += 1)
          <String, Object?>{
            'row': 99,
            'start_col': 0,
            'end_col': 1,
            'uri': 'https://invalid.test/$index',
          },
        <String, Object?>{
          'row': 0,
          'start_col': 0,
          'end_col': 1,
          'uri': 'https://inside.test',
        },
      ];
      final protobufLinks = <frame_pb.TerminalHyperlinkRange>[
        for (var index = 0; index < _maxHyperlinksPerFrame; index += 1)
          frame_pb.TerminalHyperlinkRange(
            row: 99,
            startCol: 0,
            endCol: 1,
            uri: 'https://invalid.test/$index',
          ),
        frame_pb.TerminalHyperlinkRange(
          row: 0,
          startCol: 0,
          endCol: 1,
          uri: 'https://inside.test',
        ),
      ];
      final jsonFrame = TerminalFrameDiff.fromJson(
        _jsonFrame(hyperlinks: jsonLinks),
      );
      final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
        frame_pb.TerminalFrameDiff(
          viewportRows: 1,
          viewportCols: 80,
          hyperlinks: protobufLinks,
        ).writeToBuffer(),
      );
      const expected = <String>['https://inside.test'];

      expect(protobufFrame.hyperlinks.map((link) => link.uri), expected);
      expect(jsonFrame.hyperlinks.map((link) => link.uri), expected);
      expect(
        terminalFrameProjection(protobufFrame),
        terminalFrameProjection(jsonFrame),
      );
    });

    test(
      'context-invalid inline images do not consume the valid image cap',
      () {
        final jsonImages = <Object?>[
          for (var index = 0; index < _maxInlineImagesPerFrame; index += 1)
            <String, Object?>{
              'data': base64Encode(<int>[index]),
              'row': 99,
              'col': 0,
              'width_cells': 1,
              'height_cells': 1,
            },
          <String, Object?>{
            'data': base64Encode(const <int>[255]),
            'row': 0,
            'col': 0,
            'width_cells': 1,
            'height_cells': 1,
          },
        ];
        final protobufImages = <frame_pb.TerminalInlineImage>[
          for (var index = 0; index < _maxInlineImagesPerFrame; index += 1)
            frame_pb.TerminalInlineImage(
              data: base64Encode(<int>[index]),
              row: 99,
              col: 0,
              widthCells: 1,
              heightCells: 1,
            ),
          frame_pb.TerminalInlineImage(
            data: base64Encode(const <int>[255]),
            row: 0,
            col: 0,
            widthCells: 1,
            heightCells: 1,
          ),
        ];
        final jsonFrame = TerminalFrameDiff.fromJson(
          _jsonFrame(inlineImages: jsonImages),
        );
        final protobufFrame = TerminalFrameDiff.fromProtobufBytes(
          frame_pb.TerminalFrameDiff(
            viewportRows: 1,
            viewportCols: 80,
            inlineImages: protobufImages,
          ).writeToBuffer(),
        );
        const expected = <List<int>>[
          <int>[255],
        ];

        expect(
          protobufFrame.inlineImages.map(
            (image) => image.bytes.toList(growable: false),
          ),
          expected,
        );
        expect(
          jsonFrame.inlineImages.map(
            (image) => image.bytes.toList(growable: false),
          ),
          expected,
        );
        expect(
          terminalFrameProjection(protobufFrame),
          terminalFrameProjection(jsonFrame),
        );
      },
    );

    test('viewport bounds reject layout before invoking expensive decode', () {
      var decodeCalls = 0;
      final decodedDimensions = <(int, int)>[];
      (int, int)? decode({required int widthCells, required int heightCells}) {
        decodeCalls += 1;
        final dimensions = (widthCells, heightCells);
        decodedDimensions.add(dimensions);
        return dimensions;
      }

      for (var index = 0; index < 128; index += 1) {
        final result =
            TerminalFrameValidationLimits.decodeViewportBounded<(int, int)>(
              row: 2 + index,
              col: 0,
              widthCells: 8,
              heightCells: 4,
              viewportRows: 2,
              viewportCols: 3,
              decode: decode,
            );
        expect(result, isNull);
      }
      expect(decodeCalls, 0);
      expect(decodedDimensions, isEmpty);

      final valid =
          TerminalFrameValidationLimits.decodeViewportBounded<(int, int)>(
            row: 1,
            col: 2,
            widthCells: 8,
            heightCells: 4,
            viewportRows: 2,
            viewportCols: 3,
            decode: decode,
          );

      expect(valid, (1, 1));
      expect(decodeCalls, 1);
      expect(decodedDimensions, <(int, int)>[(1, 1)]);
    });
  });
}

const int _maxNativeDimension = 0xffff;
const int _maxStyleRunsPerRow = 1024;
const int _maxHyperlinksPerFrame = 4096;
const int _maxInlineImagesPerFrame = 32;
const int _malformedCollectionSlack = 64;
const int _malformedCollectionScanMultiplier = 4;

int _maxViewportBoundedEntries(int viewportRows) {
  if (viewportRows <= 0) {
    return _malformedCollectionSlack;
  }
  return (viewportRows + _malformedCollectionSlack).clamp(
    0,
    _maxNativeDimension,
  );
}

int _maxEntriesToScan(int maxEntries) {
  return (maxEntries * _malformedCollectionScanMultiplier).clamp(
    0,
    _maxNativeDimension,
  );
}

Map<String, Object?> _jsonFrame({
  String frameKind = 'snapshot',
  List<Object?> rows = const <Object?>[],
  int viewportRows = 1,
  int viewportCols = 80,
  List<Object?> dirtyRanges = const <Object?>[],
  Map<String, Object?>? modes,
  List<Object?> hyperlinks = const <Object?>[],
  List<Object?> inlineImages = const <Object?>[],
  List<Object?> graphics = const <Object?>[],
}) {
  return <String, Object?>{
    'frame_schema_version': 'terminal-frame-diff-v1',
    'frame_kind': frameKind,
    'rows': rows,
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': false},
    'viewport_rows': viewportRows,
    'viewport_cols': viewportCols,
    'dirty_ranges': dirtyRanges,
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'modes': ?modes,
    'hyperlinks': hyperlinks,
    'inline_images': inlineImages,
    'graphics': graphics,
  };
}

Map<String, Object?> _jsonGraphic() {
  return <String, Object?>{
    'placement_id': 1,
    'render_id': 2,
    'asset_id': 3,
    'asset_version': 4,
    'protocol': 'kitty',
    'row': 0,
    'col': 0,
    'width_px': 8,
    'height_px': 4,
    'width_cells': 2,
    'height_cells': 1,
    'preserve_aspect_ratio': false,
  };
}

frame_pb.TerminalGraphicPlacement _protobufGraphic() {
  return frame_pb.TerminalGraphicPlacement(
    placementId: Int64(1),
    renderId: Int64(2),
    assetKey: frame_pb.TerminalGraphicAssetKey(
      assetId: Int64(3),
      assetVersion: Int64(4),
    ),
    protocol: 'kitty',
    row: 0,
    col: 0,
    widthPx: 8,
    heightPx: 4,
    widthCells: 2,
    heightCells: 1,
    preserveAspectRatio: false,
  );
}
