import 'dart:typed_data';

import '../proto/frame_diff.pb.dart' as frame_pb;
import '../terminal/terminal_frame_decode_ports.dart';

final class TerminalProtobufFramePacketCodec
    implements TerminalFramePacketDecodePort {
  const TerminalProtobufFramePacketCodec();

  @override
  TerminalFramePacketEnvelope decode(Uint8List bytes) {
    final frame_pb.TerminalFramePacketV1 packet;
    try {
      packet = frame_pb.TerminalFramePacketV1.fromBuffer(bytes);
    } on Object {
      throw const FormatException('Invalid Frame Packet v1 protobuf payload');
    }
    final hasFrame = packet.hasFrame();
    return TerminalFramePacketEnvelope(
      hasSchemaVersion: packet.hasSchemaVersion(),
      schemaVersion: packet.schemaVersion,
      hasContract: packet.hasContract(),
      contract: packet.contract,
      hasMessageClass: packet.hasMessageClass(),
      messageClass: packet.messageClass,
      hasMessageName: packet.hasMessageName(),
      messageName: packet.messageName,
      hasSessionId: packet.hasSessionId(),
      sessionId: packet.sessionId,
      sequence: packet.sequence.toInt(),
      sequenceIsNegative: packet.sequence.isNegative,
      hasTimestampMicros: packet.hasTimestampMicros(),
      timestampMicros: packet.timestampMicros.toInt(),
      hasFrameSchemaVersion: packet.hasFrameSchemaVersion(),
      frameSchemaVersion: packet.frameSchemaVersion,
      hasFrame: hasFrame,
      nestedFrameSchemaVersion: hasFrame && packet.frame.hasFrameSchemaVersion()
          ? packet.frame.frameSchemaVersion
          : null,
      nestedFrameBytes: hasFrame
          ? Uint8List.fromList(packet.frame.writeToBuffer())
          : null,
    );
  }
}
