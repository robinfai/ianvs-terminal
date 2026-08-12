import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal_core/src/transport/terminal_protobuf_frame_codec.dart';

import 'support/terminal_frame_wire_fixture.dart';

void main() {
  const codec = TerminalProtobufFrameCodec();

  test('decodes the complete current terminal-frame-diff-v1 contract', () {
    final fixture = completeTerminalFrameWireFixture();

    final frame = codec.decode(fixture.protobufBytes);

    expect(frame.frameSchemaVersion, 'terminal-frame-diff-v1');
    expect(frame.frameKind.name, 'delta');
    expect(frame.rows.single.text, 'A界z');
    expect(frame.graphics.single.protocol, 'kitty');
    expect(frame.inlineButtons, hasLength(2));
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
