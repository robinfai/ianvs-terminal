import 'dart:typed_data';

import '../terminal/terminal_models.dart';

final class TerminalProtobufFrameDecoder {
  const TerminalProtobufFrameDecoder();

  TerminalFrameDiff? decode(Uint8List rawFrame) {
    try {
      return TerminalFrameDiff.fromProtobufBytes(rawFrame);
    } on Object {
      return null;
    }
  }
}
