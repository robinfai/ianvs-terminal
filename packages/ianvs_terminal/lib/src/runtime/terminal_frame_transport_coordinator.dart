import 'dart:typed_data';

import 'package:ianvs_pty/ianvs_pty.dart';

import 'terminal_backend_request_error.dart';
import 'terminal_frame_decoder.dart';
import 'terminal_frame_packet_v1.dart';

enum TerminalFrameWireFormatPreference { automatic, json }

final class TerminalFrameTransportCoordinator {
  TerminalFrameTransportCoordinator({
    required PtySessionBackend backend,
    required TerminalFrameDecoder decoder,
    required TerminalFrameWireFormatPreference preference,
    TerminalFramePacketV1Decoder packetDecoder =
        const TerminalFramePacketV1Decoder(),
    TerminalBackendRequestErrorHandler? onRequestError,
  }) : _backend = backend,
       _decoder = decoder,
       _packetDecoder = packetDecoder,
       _preference = preference,
       _onRequestError = onRequestError;

  final PtySessionBackend _backend;
  final TerminalFrameDecoder _decoder;
  final TerminalFramePacketV1Decoder _packetDecoder;
  final TerminalFrameWireFormatPreference _preference;
  final TerminalBackendRequestErrorHandler? _onRequestError;
  final Map<String, int> _lastFramePacketSequences = <String, int>{};

  TerminalDecodedFrame? take(String sessionId) {
    if (_preference == TerminalFrameWireFormatPreference.json) {
      return _takeJson(sessionId);
    }

    final backend = _backend;
    final packetBackend = backend is PtySessionFramePacketV1Backend
        ? backend as PtySessionFramePacketV1Backend
        : null;
    if (packetBackend != null && packetBackend.supportsFramePacketV1) {
      return _takeFramePacketV1(sessionId, packetBackend);
    }
    final protobufBackend = backend is PtySessionProtobufFrameBackend
        ? backend as PtySessionProtobufFrameBackend
        : null;
    if (protobufBackend != null && protobufBackend.supportsProtobufFrameDiffs) {
      return _takeProtobuf(sessionId, protobufBackend);
    }
    return _takeJson(sessionId);
  }

  TerminalDecodedFrame? _takeJson(String sessionId) {
    final String? rawFrame;
    try {
      rawFrame = _backend.takeFrameDiffJson(sessionId);
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(sessionId, 'takeFrameDiffJson', error, stackTrace);
      return null;
    }
    if (rawFrame == null || rawFrame.isEmpty) {
      return null;
    }
    return _decoder.decodeJson(rawFrame);
  }

  TerminalDecodedFrame? _takeProtobuf(
    String sessionId,
    PtySessionProtobufFrameBackend backend,
  ) {
    final Uint8List? rawFrame;
    try {
      rawFrame = backend.takeFrameDiffProtobuf(sessionId);
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(
        sessionId,
        'takeFrameDiffProtobuf',
        error,
        stackTrace,
      );
      return null;
    }
    if (rawFrame == null || rawFrame.isEmpty) {
      return null;
    }
    return _decoder.decodeProtobuf(rawFrame);
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

    final decodeWatch = _decoder.collectMetrics ? (Stopwatch()..start()) : null;
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
      metrics: _decoder.collectMetrics
          ? TerminalFrameDecodeMetrics(
              rawFrameBytes: rawPacket.length,
              wireFormat: 'protobuf',
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
