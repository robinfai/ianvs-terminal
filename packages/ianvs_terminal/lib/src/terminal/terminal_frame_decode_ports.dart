import 'dart:typed_data';

import 'terminal_models.dart';

abstract interface class TerminalJsonFrameDecodePort {
  TerminalFrameDiff? decode(String rawFrame);
}

abstract interface class TerminalBinaryFrameDecodePort {
  TerminalFrameDiff? decode(Uint8List rawFrame);
}

abstract interface class TerminalBinaryFrameCodecPort {
  TerminalFrameDiff decode(List<int> bytes);
}

abstract interface class TerminalFramePacketDecodePort {
  TerminalFramePacketEnvelope decode(Uint8List bytes);
}

final class TerminalFramePacketEnvelope {
  const TerminalFramePacketEnvelope({
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
