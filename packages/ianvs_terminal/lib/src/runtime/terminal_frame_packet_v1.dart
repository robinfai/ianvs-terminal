import 'dart:typed_data';

import '../proto/frame_diff.pb.dart' as frame_pb;
import '../terminal/terminal_models.dart';

const int terminalFramePacketV1SchemaVersion = 1;
const String terminalFramePacketV1Contract = 'ianvs-terminal-frame-packet-v1';
const int _maxTerminalFramePacketBytes = 64 * 1024 * 1024;
final RegExp _sessionIdPattern = RegExp(r'^[0-9]+$');
final BigInt _maxUint64 = BigInt.parse('18446744073709551615');

final class TerminalFramePacketContractException implements Exception {
  const TerminalFramePacketContractException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'TerminalFramePacketContractException($code): $message';
}

final class TerminalFramePacketV1 {
  const TerminalFramePacketV1({
    required this.sessionId,
    required this.sequence,
    required this.timestampMicros,
    required this.frameSchemaVersion,
    required this.frame,
  });

  final String sessionId;
  final int sequence;
  final int timestampMicros;
  final String frameSchemaVersion;
  final TerminalFrameDiff frame;
}

final class TerminalFramePacketV1Decoder {
  const TerminalFramePacketV1Decoder();

  TerminalFramePacketV1 decode(
    Uint8List bytes, {
    required String expectedSessionId,
    required int? afterSequence,
  }) {
    if (bytes.isEmpty || bytes.length > _maxTerminalFramePacketBytes) {
      throw const TerminalFramePacketContractException(
        'frame_packet_size_invalid',
        'Frame Packet v1 must contain between 1 byte and 64 MiB',
      );
    }
    if (!_isValidSessionId(expectedSessionId)) {
      throw const TerminalFramePacketContractException(
        'frame_packet_expected_session_invalid',
        'Expected session identity must be a positive decimal uint64',
      );
    }
    if (afterSequence != null && afterSequence < 0) {
      throw const TerminalFramePacketContractException(
        'frame_packet_after_sequence_invalid',
        'Acknowledged sequence must be non-negative',
      );
    }

    final frame_pb.TerminalFramePacketV1 packet;
    try {
      packet = frame_pb.TerminalFramePacketV1.fromBuffer(bytes);
    } on Object catch (error) {
      throw TerminalFramePacketContractException(
        'frame_packet_protobuf_invalid',
        'Frame Packet v1 protobuf could not be decoded: $error',
      );
    }

    if (!packet.hasSchemaVersion() ||
        packet.schemaVersion != terminalFramePacketV1SchemaVersion) {
      throw TerminalFramePacketContractException(
        'frame_packet_schema_unsupported',
        'Unsupported Frame Packet schema version ${packet.schemaVersion}',
      );
    }
    if (!packet.hasContract() ||
        packet.contract != terminalFramePacketV1Contract) {
      throw const TerminalFramePacketContractException(
        'frame_packet_contract_mismatch',
        'Frame Packet contract identifier does not match v1',
      );
    }
    if (!packet.hasMessageClass() || packet.messageClass != 'frame') {
      throw const TerminalFramePacketContractException(
        'frame_packet_message_class_mismatch',
        'Frame Packet message_class must be frame',
      );
    }
    if (!packet.hasMessageName() || packet.messageName != 'frame_diff') {
      throw const TerminalFramePacketContractException(
        'frame_packet_message_name_mismatch',
        'Frame Packet message_name must be frame_diff',
      );
    }
    if (!packet.hasSessionId() || !_isValidSessionId(packet.sessionId)) {
      throw const TerminalFramePacketContractException(
        'frame_packet_session_invalid',
        'Frame Packet session identity must be a positive decimal uint64',
      );
    }
    if (packet.sessionId != expectedSessionId) {
      throw TerminalFramePacketContractException(
        'frame_packet_session_mismatch',
        'Frame Packet session ${packet.sessionId} does not match '
            '$expectedSessionId',
      );
    }
    if (!packet.hasSequence() || packet.sequence.isNegative) {
      throw const TerminalFramePacketContractException(
        'frame_packet_sequence_invalid',
        'Frame Packet sequence must be a uint64',
      );
    }
    if (!packet.hasTimestampMicros() || packet.timestampMicros <= 0) {
      throw const TerminalFramePacketContractException(
        'frame_packet_timestamp_invalid',
        'Frame Packet timestamp_micros must be positive',
      );
    }
    if (!packet.hasFrameSchemaVersion() ||
        packet.frameSchemaVersion !=
            TerminalFrameDiff.currentFrameSchemaVersion) {
      throw const TerminalFramePacketContractException(
        'frame_packet_frame_schema_unsupported',
        'Frame Packet frame schema is unsupported',
      );
    }
    if (!packet.hasFrame() ||
        !packet.frame.hasFrameSchemaVersion() ||
        packet.frame.frameSchemaVersion != packet.frameSchemaVersion) {
      throw const TerminalFramePacketContractException(
        'frame_packet_frame_invalid',
        'Frame Packet must contain a matching versioned terminal frame',
      );
    }

    final int sequence = packet.sequence.toInt();
    final TerminalFrameDiff frame;
    try {
      frame = TerminalFrameDiff.fromProtobufBytes(packet.frame.writeToBuffer());
    } on Object catch (error) {
      throw TerminalFramePacketContractException(
        'frame_packet_frame_invalid',
        'Nested terminal frame could not be decoded: $error',
      );
    }

    if (afterSequence == null) {
      if (frame.frameKind != TerminalFrameKind.snapshot) {
        throw const TerminalFramePacketContractException(
          'frame_packet_initial_delta',
          'The first accepted Frame Packet must contain a Snapshot',
        );
      }
    } else {
      if (sequence <= afterSequence) {
        throw TerminalFramePacketContractException(
          'frame_packet_sequence_reordered',
          'Frame Packet sequence $sequence is not newer than $afterSequence',
        );
      }
      if (sequence != afterSequence + 1 &&
          frame.frameKind != TerminalFrameKind.snapshot) {
        throw TerminalFramePacketContractException(
          'frame_packet_sequence_gap',
          'Frame Packet sequence $sequence does not follow $afterSequence',
        );
      }
    }

    return TerminalFramePacketV1(
      sessionId: packet.sessionId,
      sequence: sequence,
      timestampMicros: packet.timestampMicros.toInt(),
      frameSchemaVersion: packet.frameSchemaVersion,
      frame: frame,
    );
  }
}

bool _isValidSessionId(String value) {
  if (!_sessionIdPattern.hasMatch(value)) {
    return false;
  }
  final parsed = BigInt.parse(value);
  return parsed > BigInt.zero && parsed <= _maxUint64;
}
