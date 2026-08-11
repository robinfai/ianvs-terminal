import 'dart:typed_data';

import '../terminal/terminal_frame_decode_ports.dart';
import '../terminal/terminal_models.dart';
import 'terminal_protobuf_frame_codec.dart';

final class TerminalProtobufFrameDecoder
    implements TerminalBinaryFrameDecodePort {
  const TerminalProtobufFrameDecoder({
    this.codec = const TerminalProtobufFrameCodec(),
  });

  final TerminalProtobufFrameCodec codec;

  @override
  TerminalFrameDiff? decode(Uint8List rawFrame) {
    try {
      return codec.decode(rawFrame);
    } on Object {
      return null;
    }
  }
}
