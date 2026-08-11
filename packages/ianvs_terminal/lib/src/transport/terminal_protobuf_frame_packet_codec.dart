import 'dart:typed_data';

import '../proto/frame_diff.pb.dart' as frame_pb;

/// Transport-only projection of the generated Frame Packet protobuf envelope.
///
/// Runtime contract validation consumes this neutral value and obtains the
/// nested domain frame through `TerminalProtobufFrameCodec`.
final class TerminalProtobufFramePacketEnvelope {
  const TerminalProtobufFramePacketEnvelope({
    required this.hasSchemaVersion,
    required this.schemaVersion,
    required this.hasContract,
    required this.contract,
    required this.hasMessageClass,
    required this.messageClass,
    required this.hasMessageName,
    required this.messageName,
    required this.hasSessionId,
    required this.sessionId,
    required this.sequence,
    required this.sequenceIsNegative,
    required this.hasTimestampMicros,
    required this.timestampMicros,
    required this.hasFrameSchemaVersion,
    required this.frameSchemaVersion,
    required this.hasFrame,
    required this.nestedFrameSchemaVersion,
    required this.nestedFrameBytes,
  });

  final bool hasSchemaVersion;
  final int schemaVersion;
  final bool hasContract;
  final String contract;
  final bool hasMessageClass;
  final String messageClass;
  final bool hasMessageName;
  final String messageName;
  final bool hasSessionId;
  final String sessionId;
  final int sequence;
  final bool sequenceIsNegative;
  final bool hasTimestampMicros;
  final int timestampMicros;
  final bool hasFrameSchemaVersion;
  final String frameSchemaVersion;
  final bool hasFrame;
  final String? nestedFrameSchemaVersion;
  final Uint8List? nestedFrameBytes;
}

final class TerminalProtobufFramePacketCodec {
  const TerminalProtobufFramePacketCodec();

  TerminalProtobufFramePacketEnvelope decode(Uint8List bytes) {
    final frame_pb.TerminalFramePacketV1 packet;
    try {
      packet = frame_pb.TerminalFramePacketV1.fromBuffer(bytes);
    } on Object {
      throw const FormatException('Invalid Frame Packet v1 protobuf payload');
    }
    final hasFrame = packet.hasFrame();
    return TerminalProtobufFramePacketEnvelope(
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
