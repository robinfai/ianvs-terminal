import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal_core/src/terminal/terminal_models.dart';
import 'package:ianvs_terminal_core/src/transport/terminal_protobuf_frame_codec.dart';

import 'support/terminal_frame_wire_fixture.dart';

void main() {
  const codec = TerminalProtobufFrameCodec();

  frame_pb.TerminalFrameDiff semanticFrame() =>
      completeTerminalFrameWireFixture().protobuf
        ..semanticSnapshotToken = '18446744073709551615'
        ..semanticBlocks.add(
          frame_pb.TerminalSemanticBlock(
            id: 'block-1',
            cwd: '/historical',
            contextId: 'root',
            sftpContextId: 'nested@1',
            shellHostname: 'declared',
            shellUsername: 'user',
          ),
        )
        ..semanticRowContexts.add(
          frame_pb.TerminalSemanticRowContext(
            viewportRow: 0,
            blockId: 'block-1',
          ),
        );

  test(
    'decodes immutable frame provenance and replaces all ownership on delta',
    () {
      final frame = codec.decode(semanticFrame().writeToBuffer());
      expect(frame.semanticSnapshotToken, '18446744073709551615');
      expect(frame.semanticBlocks['block-1']!.cwd, '/historical');
      expect(frame.semanticBlocks['block-1']!.sftpContextId, 'nested@1');
      expect(frame.semanticRowContexts[0], 'block-1');
      expect(
        () => frame.semanticRowContexts[1] = 'block-1',
        throwsUnsupportedError,
      );
      final state = TerminalViewportState.empty.applySnapshot(frame);
      expect(state.frame.semanticSnapshotToken, frame.semanticSnapshotToken);
      final next = semanticFrame()
        ..semanticSnapshotToken = '2'
        ..semanticBlocks.clear()
        ..semanticRowContexts.clear();
      final advanced = state.applyDelta(codec.decode(next.writeToBuffer()));
      expect(advanced.frame.semanticSnapshotToken, '2');
      expect(advanced.frame.semanticRowContexts, isEmpty);
      final missing = advanced.applyDelta(
        codec.decode(completeTerminalFrameWireFixture().protobufBytes),
      );
      expect(missing.frame.semanticSnapshotToken, isNull);
      expect(missing.frame.semanticBlocks, isEmpty);
    },
  );

  test('rejects malformed or ambiguous current frame provenance', () {
    final bad = <frame_pb.TerminalFrameDiff>[
      semanticFrame()..clearSemanticSnapshotToken(),
      for (final token in ['', '0', '-1', '01', '18446744073709551616'])
        semanticFrame()..semanticSnapshotToken = token,
      semanticFrame()
        ..semanticBlocks.add(
          frame_pb.TerminalSemanticBlock(id: 'block-1', cwd: '/other'),
        ),
      semanticFrame()
        ..semanticRowContexts.add(
          frame_pb.TerminalSemanticRowContext(
            viewportRow: 0,
            blockId: 'block-1',
          ),
        ),
      semanticFrame()..semanticRowContexts[0].blockId = 'missing',
      semanticFrame()..semanticRowContexts[0].viewportRow = 100000,
      semanticFrame()..semanticBlocks[0].cwd = '/bad\u0000path',
      semanticFrame()..semanticBlocks[0].cwd = 'x' * 4097,
      semanticFrame()..semanticBlocks[0].cwd = '',
      semanticFrame()..semanticBlocks[0].cwd = '界' * 1366,
      semanticFrame()..semanticBlocks[0].contextId = '界' * 43,
      semanticFrame()..semanticBlocks[0].shellHostname = '界' * 86,
      semanticFrame()..semanticBlocks[0].sftpContextId = '',
      semanticFrame()..semanticBlocks[0].sftpContextId = 'x' * 86,
      semanticFrame()..semanticBlocks[0].sftpContextId = 'nested/1',
    ];
    for (final proto in bad) {
      expect(() => codec.decode(proto.writeToBuffer()), throwsFormatException);
    }
  });

  test(
    'accepts proto3 row zero omitted from serialized ownership messages',
    () {
      // TerminalSemanticRowContext wire bytes: only field 2 (block_id).
      // Non-optional uint32 field 1 is absent, as emitted by prost for zero.
      const omittedZeroWire = <int>[
        0x12,
        0x07,
        0x62,
        0x6c,
        0x6f,
        0x63,
        0x6b,
        0x2d,
        0x31,
      ];
      final row = frame_pb.TerminalSemanticRowContext.fromBuffer(
        omittedZeroWire,
      );
      expect(row.hasViewportRow(), isFalse);
      expect(row.viewportRow, 0);
      final proto = semanticFrame()
        ..semanticRowContexts.clear()
        ..semanticRowContexts.add(row);
      final encoded = proto.writeToBuffer();
      expect(
        frame_pb.TerminalFrameDiff.fromBuffer(
          encoded,
        ).semanticRowContexts.single.hasViewportRow(),
        isFalse,
      );
      expect(codec.decode(encoded).semanticRowContexts, {0: 'block-1'});

      // Both omitted zero and explicit zero address the same physical row.
      proto.semanticRowContexts.add(
        frame_pb.TerminalSemanticRowContext(viewportRow: 0, blockId: 'block-1'),
      );
      expect(() => codec.decode(proto.writeToBuffer()), throwsFormatException);
    },
  );

  test('decodes the complete current terminal-frame-diff-v1 contract', () {
    final fixture = completeTerminalFrameWireFixture();

    final frame = codec.decode(fixture.protobufBytes);

    expect(frame.frameSchemaVersion, 'terminal-frame-diff-v1');
    expect(frame.frameKind.name, 'delta');
    expect(frame.rows.single.text, 'A界z');
    expect(frame.graphics.single.protocol, 'kitty');
    expect(frame.inlineButtons, hasLength(2));
  });

  test('rejects semantic tables exceeding row block or byte budgets', () {
    final blocks = semanticFrame()
      ..semanticBlocks.addAll(
        List.generate(
          128,
          (i) => frame_pb.TerminalSemanticBlock(id: 'extra-$i', cwd: '/'),
        ),
      );
    final rows = semanticFrame()
      ..viewportRows = 1024
      ..semanticRowContexts.addAll(
        List.generate(
          512,
          (i) => frame_pb.TerminalSemanticRowContext(
            viewportRow: i + 1,
            blockId: 'block-1',
          ),
        ),
      );
    final bytes = semanticFrame()
      ..semanticBlocks.addAll(
        List.generate(
          65,
          (i) =>
              frame_pb.TerminalSemanticBlock(id: 'large-$i', cwd: 'x' * 4096),
        ),
      );
    for (final proto in [blocks, rows, bytes]) {
      expect(() => codec.decode(proto.writeToBuffer()), throwsFormatException);
    }
  });

  test('rejects a missing, empty, or non-current nested schema', () {
    final valid = completeTerminalFrameWireFixture().protobuf;
    final missing = valid.deepCopy()..clearFrameSchemaVersion();
    final empty = valid.deepCopy()..frameSchemaVersion = '';
    final future = valid.deepCopy()
      ..frameSchemaVersion = 'terminal-frame-diff-v2';

    for (final proto in <frame_pb.TerminalFrameDiff>[missing, empty, future]) {
      expect(() => codec.decode(proto.writeToBuffer()), throwsFormatException);
    }
  });

  test('rejects missing, unspecified, and unknown frame kinds', () {
    final valid = completeTerminalFrameWireFixture().protobuf;
    final missing = valid.deepCopy()..clearFrameKind();
    final unspecified = valid.deepCopy()
      ..frameKind = frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_UNSPECIFIED;
    final unknown = <int>[
      ...(valid.deepCopy()..clearFrameKind()).writeToBuffer(),
      0x10,
      0x63,
    ];

    expect(() => codec.decode(missing.writeToBuffer()), throwsFormatException);
    expect(
      () => codec.decode(unspecified.writeToBuffer()),
      throwsFormatException,
    );
    expect(() => codec.decode(unknown), throwsFormatException);
  });
}
