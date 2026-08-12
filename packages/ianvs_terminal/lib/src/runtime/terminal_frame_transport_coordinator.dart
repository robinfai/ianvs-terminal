import 'dart:typed_data';

import 'package:ianvs_pty/ianvs_pty.dart';

import '../transport/terminal_protobuf_frame_codec.dart';
import '../transport/terminal_protobuf_frame_packet_codec.dart';
import 'terminal_backend_request_error.dart';
import 'terminal_frame_decoder.dart';
import 'terminal_frame_packet_v1.dart';

final class TerminalFrameTransportCoordinator {
  TerminalFrameTransportCoordinator({
    required PtySessionBackend backend,
    bool collectMetrics = false,
    TerminalFramePacketV1Decoder? packetDecoder,
    TerminalBackendRequestErrorHandler? onRequestError,
  }) : _backend = backend,
       _collectMetrics = collectMetrics,
       _packetDecoder =
           packetDecoder ??
           const TerminalFramePacketV1Decoder(
             frameCodec: TerminalProtobufFrameCodec(),
             packetCodec: TerminalProtobufFramePacketCodec(),
           ),
       _onRequestError = onRequestError;

  final PtySessionBackend _backend;
  final bool _collectMetrics;
  final TerminalFramePacketV1Decoder _packetDecoder;
  final TerminalBackendRequestErrorHandler? _onRequestError;
  final Map<String, int> _lastFramePacketSequences = <String, int>{};

  TerminalDecodedFrame? take(String sessionId) {
    final backend = _backend;
    final packetBackend = backend is PtySessionFramePacketV1Backend
        ? backend as PtySessionFramePacketV1Backend
        : null;
    if (packetBackend == null) {
      throw UnsupportedError(
        'The native terminal runtime must provide Frame Packet v1',
      );
    }
    return _takeFramePacketV1(sessionId, packetBackend);
  }

  TerminalDecodedFrame? _takeFramePacketV1(
    String sessionId,
    PtySessionFramePacketV1Backend backend,
  ) {
    final afterSequence = _lastFramePacketSequences[sessionId];
    final Uint8List? rawPacket;
    try {
      rawPacket = backend.takeFramePacketV1Protobuf(
        sessionId,
        afterSequence: afterSequence,
      );
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(
        sessionId,
        'takeFramePacketV1Protobuf',
        error,
        stackTrace,
      );
      return null;
    }
    if (rawPacket == null || rawPacket.isEmpty) {
      return null;
    }

    final decodeWatch = _collectMetrics ? (Stopwatch()..start()) : null;
    final TerminalFramePacketV1 packet;
    try {
      packet = _packetDecoder.decode(
        rawPacket,
        expectedSessionId: sessionId,
        afterSequence: afterSequence,
      );
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(
        sessionId,
        'takeFramePacketV1Protobuf',
        error,
        stackTrace,
      );
      return null;
    }
    decodeWatch?.stop();
    _lastFramePacketSequences[sessionId] = packet.sequence;
    return TerminalDecodedFrame(
      frame: packet.frame,
      metrics: _collectMetrics
          ? TerminalFrameDecodeMetrics(
              rawFrameBytes: rawPacket.length,
              wireFormat: 'frame-packet.protobuf.v1',
              jsonDecodeMicros: 0,
              protobufDecodeMicros: decodeWatch?.elapsedMicroseconds ?? 0,
            )
          : null,
    );
  }

  void removeSession(String sessionId) {
    _lastFramePacketSequences.remove(sessionId);
  }
}
